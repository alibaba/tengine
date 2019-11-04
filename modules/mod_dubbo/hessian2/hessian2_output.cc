#include "hessian2_output.h"
#include "hessian2_ext.h"
#include "objects.h"
#include "utils.h"

namespace hessian {

using namespace std;

void hessian2_output::clear() {
    _refs_map.clear();
    _ref_idx = 0;
}

/*
 *            # null value
 * null       ::= 'N'
 */
void hessian2_output::write_null() {
    print_8bit('N');
}

/*
 *            # boolean true/false
 * boolean    ::= 'T'
 *            ::= 'F'
 */
void hessian2_output::write_bool(bool b) {
    print_8bit(b ? 'T' : 'F');
}


/*
 *           # 32-bit signed integer
 * int       ::= 'I' b3 b2 b1 b0
 *           ::= [x80-xbf]             # -x10 to x3f
 *           ::= [xc0-xcf] b0          # -x800 to x7ff
 *           ::= [xd0-xd7] b1 b0       # -x40000 to x3ffff
 */
void hessian2_output::write_int32(int32_t value) {
    //just use ::= 'I' b3 b2 b1 b0
    print_8bit('I');
    print_32bit(value);
}

/*
 *            # 64-bit signed long integer
 * long       ::= 'L' b7 b6 b5 b4 b3 b2 b1 b0
 *            ::= [xd8-xef]             # -x08 to x0f
 *            ::= [xf0-xff] b0          # -x800 to x7ff
 *            ::= [x38-x3f] b1 b0       # -x40000 to x3ffff
 *            ::= x59 b3 b2 b1 b0       # 32-bit integer cast to long
 */
void hessian2_output::write_int64(int64_t value) {
    //just use ::= 'L' b7 b6 b5 b4 b3 b2 b1 b0
    print_8bit('L');
    print_64bit(value);
}

/*
 *            # 64-bit IEEE double
 * double     ::= 'D' b7 b6 b5 b4 b3 b2 b1 b0
 *            ::= x5b                   # 0.0
 *            ::= x5c                   # 1.0
 *            ::= x5d b0                # byte cast to double
 *                                      #  (-128.0 to 127.0)
 *            ::= x5e b1 b0             # short cast to double
 *            ::= x5f b3 b2 b1 b0       # 32-bit float cast to double
 */
void hessian2_output::write_double(double d_val) {
    //just use ::= 'D' b7 b6 b5 b4 b3 b2 b1 b0
    print_8bit('D');
    print_64bit(double_to_long(d_val));
}

/*
 *            # time in UTC encoded as 64-bit long milliseconds since
 *            #  epoch
 * date       ::= x4a b7 b6 b5 b4 b3 b2 b1 b0
 *            ::= x4b b3 b2 b1 b0       # minutes since epoch
 */
void hessian2_output::write_utc_date(int64_t milli_epoch) {
    //just use ::= x4a b7 b6 b5 b4 b3 b2 b1 b0
    print_8bit('J');
    print_64bit(milli_epoch);
}


/*
 *            # UTF-8 encoded character string split into 64k chunks
 * string     ::= x52 b1 b0 <utf8-data> string  # non-final chunk
 *            ::= 'S' b1 b0 <utf8-data>         # string of length
 *                                              #  0-65535
 *            ::= [x00-x1f] <utf8-data>         # string of length
 *                                              #  0-31
 *            ::= [x30-x34] <utf8-data>         # string of length
 */
void hessian2_output::write_utf8_string(const char* str, uint32_t byte_size) {
    //hessian2 use utf8 charset standard

    if (str == NULL || byte_size == 0) {
        write_null();
        return;
    }

    // begin new chunk
    uint32_t patch_pos = _data->length();
    _data->reserve(patch_pos + byte_size + byte_size / 10240 + 3);

    uint32_t len = 0, last = 0;
    const char *cur = str;
    size_t i;
    const uint32_t max_chunk_byte_size = 0x8000;

    for (i = 0; i< byte_size; ) {
        len++;
        if (str[i] & 0x80) {
            // more than one byte for this char
            if ((str[i] & 0xe0) == 0xc0) {
                i += 2;
            } else if ((str[i] & 0xf0) == 0xe0) {
                i += 3;
            } else {
                i += 4;
            }
        } else {
            i++;
        }

        if (len >= max_chunk_byte_size) {
            print_8bit('R');
            print_8bit(len >> 8);
            print_8bit(len);

            _data->append(cur, i - last);

            len = 0;
            cur = str + i;
            last = i;
        }
    }

    if(len <= 0) {
        return;
    } else if (len <= 31) {
        print_8bit(len);
    } else if(len <= 1023) {
        print_8bit((char)(48 + (len >> 8)));
        print_8bit((char)len);
    } else {
        print_8bit('S');
        print_8bit(len >> 8);
        print_8bit(len);
    }

    _data->append(cur, i - last);
}

/*
 *
 *            # 8-bit binary data split into 64k chunks
 * binary     ::= x41 b1 b0 <binary-data> binary # non-final chunk
 *            ::= 'B' b1 b0 <binary-data>        # final chunk
 *            ::= [x20-x2f] <binary-data>        # binary data of
 *                                                 #  length 0-15
 *            ::= [x34-x37] <binary-data>        # binary data of
 *                                                 #  length 0-1023
 */
void hessian2_output::write_bytes(const char* bytes, uint32_t byte_size) {

    const uint32_t max_chunk_byte_size = 0x8000;

    if (bytes == NULL || byte_size == 0) {
        write_null();
        return;
    }


    _data->reserve(_data->size() + byte_size / 10240 + 3);

    for ( ; ; ) {
        if (byte_size > max_chunk_byte_size) {
            print_8bit('A');
            print_8bit(max_chunk_byte_size >> 8);
            print_8bit((uint8_t)max_chunk_byte_size);
            print_raw_bytes(bytes, max_chunk_byte_size);
            bytes += max_chunk_byte_size;

            byte_size -= max_chunk_byte_size;
        } else {
            break;
        }
    }

    if (byte_size <= 15 ) {
        print_8bit(32 + byte_size);
    } else if (byte_size <= 1023) {
        print_8bit(52 + (byte_size >> 8));
        print_8bit(byte_size);
    } else {
        print_8bit('B');
        print_8bit(byte_size >> 8);
        print_8bit(byte_size);
    }

    print_raw_bytes(bytes, byte_size);
}

void hessian2_output::write_utf8_string(const string& str) {
    write_utf8_string(str.c_str(), str.size());
}

bool hessian2_output::write_ref(const Object* object) {
    if (object == NULL || object->type_id() == Object::NULL_OBJECT) {
        hessian2_output::write_null();
        return true;
    }

    pair<map<uintptr_t, int32_t>::iterator, bool> ret = _refs_map.insert
        (pair<uintptr_t, int32_t>((uintptr_t) object, _ref_idx));

    if (ret.second == false) {
        // ref already existed, write as a reference
        write_ref(ret.first->second);
        return true;
    } else {
        ++_ref_idx;
        return false;
    }
}

void hessian2_output::write_length(uint32_t length) {
    print_8bit('l');
    print_32bit(length);
}

void hessian2_output::write_type(const std::string& type) {
    print_8bit('t');
    if (type.empty()) {
        print_raw_len_bytes("", 0);
    } else {
        print_raw_len_bytes(type.c_str(), type.size());
    }
}

/*
 *            # value reference (e.g. circular trees and graphs)
 * ref        ::= x51 int            # reference to nth map/list/object
 */
void hessian2_output::write_ref(int32_t ref_id) {
    print_8bit('Q');
    print_32bit(ref_id);
}

void hessian2_output::write_object(const Object* object) {
    if (object == NULL) {
        hessian2_output::write_null();
    } else if (object->type_id() <= Object::WEAK_REF || !write_ref(object)) {
        hessian2_serialize_pt hs = hessian2_get_serializer(object);
        if (hs) {
            hs(object, *this);
        } else {
            throw io_exception("serializer not found for object " + object->classname());
        }
    }
}

}

