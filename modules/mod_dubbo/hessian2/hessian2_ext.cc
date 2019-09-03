#include "hessian2_ext.h"
#include "utils.h"
#include "hessian2_input.h"
#include "hessian2_output.h"
#include <memory>
#include <ostream>
#include <vector>

namespace hessian {

using namespace std;

static vector<hessian2_serialize_pt> serializer_registry_hessian2;

void hessian2_regist_serializer(uint32_t type_id, hessian2_serialize_pt serializer) {
    if (type_id >= serializer_registry_hessian2.size()) {
        serializer_registry_hessian2.resize(type_id + 1);
    }
    serializer_registry_hessian2[type_id] = serializer;
}

hessian2_serialize_pt hessian2_get_serializer(const Object* obj) {
    return serializer_registry_hessian2[obj ? obj->type_id() : 0];
}

static void null_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_null();
}

static void boolean_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_bool(static_cast<const Boolean*>(obj)->data());
}

static void integer_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_int32(static_cast<const Integer*>(obj)->data());
}

static void long_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_int64(static_cast<const Long*>(obj)->data());
}

static void double_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_double(static_cast<const Double*>(obj)->data());
}

static void date_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_utc_date(static_cast<const Date*>(obj)->data());
}

static void string_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    const String* str = static_cast<const String*>(obj);
    hout.write_utf8_string(str->data().c_str(), str->data().size());
}

static void bytearray_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    const ByteArray* bs = static_cast<const ByteArray*>(obj);
    hout.write_bytes(bs->data().c_str(), bs->data().size());
}

static void reference_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    hout.write_object(static_cast<const Reference*>(obj)->data());
}

static void list_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    const List* list = static_cast<const List*>(obj);

    hout.print_8bit('V');
    hout.write_type(list->classname() == List::DEFAULT_CLASSNAME ? "" : list->classname());
    hout.write_length(list->size());

    for (List::data_type::const_iterator it = list->data().begin(); it != list->data().end(); ++it) {
        hout.write_object(*it);
    }

    hout.print_8bit('z');
}

static void map_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    const Map* map = static_cast<const Map*>(obj);

    hout.print_8bit('H');

    for (Map::data_type::const_iterator it = map->data().begin(); it != map->data().end(); ++it) {
        hout.write_object((*it).first);
        hout.write_object((*it).second);
    }

    hout.print_8bit('Z');
}

/* ==================================================================
 * deserializer
 * ================================================================ */
typedef vector<pair<string, hessian2_deserialize_pt> > deserializer_registry_hessian2_t;
static deserializer_registry_hessian2_t deserializer_registry_hessian2_strict;
static deserializer_registry_hessian2_t deserializer_registry_hessian2_suffix;

void hessian2_regist_deserializer(Object::ObjectType ext_type,
        const string& classname,
        hessian2_deserialize_pt deserializer) {
    if (ext_type != Object::EXT_MAP) {
        throw io_exception("illegal ext_type when registering hessian deserializer of " + classname);
    }

    size_t asterisk = classname.find_first_of('*');
    if (asterisk == string::npos) {
        deserializer_registry_hessian2_strict.push_back(
                deserializer_registry_hessian2_t::value_type(classname, deserializer));
    } else if (asterisk == 0 && classname.size() > 1) {
        deserializer_registry_hessian2_suffix.push_back(
                deserializer_registry_hessian2_t::value_type(classname.substr(1), deserializer));
    } else {
        throw io_exception("illegal classname when registering hessian deserializer of " + classname);
    }
}

hessian2_deserialize_pt hessian2_get_deserializer(Object::ObjectType ext_type, const string& classname) {
    if (ext_type != Object::EXT_MAP) {
        return NULL;
    }

    for (deserializer_registry_hessian2_t::const_iterator it = deserializer_registry_hessian2_strict.begin();
            it != deserializer_registry_hessian2_strict.end(); ++it) {
        if (it->first == classname) {
            return it->second;
        }
    }
    for (deserializer_registry_hessian2_t::const_iterator it = deserializer_registry_hessian2_suffix.begin();
            it != deserializer_registry_hessian2_suffix.end(); ++it) {
        if (string_ends_with(classname, it->first)) {
            return it->second;
        }
    }

    return NULL;
}

/* ==================================================================
 * Java object ext
 * ================================================================ */
static void exception_serialize_hessian2(const Object* obj, hessian2_output& hout) {
    const Exception* ex = static_cast<const Exception*>(obj);

    hout.print_8bit('M');
    hout.write_type(ex->classname());

    hout.write_utf8_string("detailMessage");
    hout.write_utf8_string(ex->detail_message());
    hout.write_utf8_string("cause");
    hout.write_object(ex->cause());

    // stack_trace different between C++/Java, not support

    //serialize other
    for (Map::data_type::const_iterator it = ex->data().begin(); it != ex->data().end(); ++it) {
        hout.write_object((*it).first);
        hout.write_object((*it).second);
    }

    hout.print_8bit('z');
}

static Object* exception_deserialize(const string& type, hessian2_input& hin) {
    Exception* ex = new Exception("", type);
    Safeguard<Exception> safeguard(ex);
    hin.add_ref(ex);

    int tag;
    while ((tag = hin.peek()) != 'z') {
        if (tag == 'S' || tag == 's') {
            string key;
            hin.read_utf8_string(&key);

            if (key == "detailMessage") {
                // deal with "String"
                hin.read_chunked_utf8_string(ex->mutable_detail_message());
            } else if (key == "cause") {
                // deal with "Exception"
                pair<Object*, bool> ret = hin.read_object();
                Object* cause = ret.first;
                if (pointer_of<Exception>(cause)) {
                    ex->set_cause((Exception*) cause, ret.second);
                } else {
                    throw io_exception("can not cast cause to Exception: " + ex->classname());
                }
            } else if (key == "stackTrace") {
                // deal with "List"
                tag = hin.parse_8bit();
                if (tag == 'V') {
                    List* stack_trace = new List(hin.read_type());
                    ex->set_stack_trace(stack_trace, true);
                    hin.add_ref(stack_trace);
                    uint32_t st_size = hin.read_length();
                    if (st_size != 0xFFFFFFFF) {
                        stack_trace->reserve(st_size);
                    }
                    for (uint32_t st_index = 0; st_index < st_size; ++st_index) {
                        // parse "StackTraceElement"
                        tag = hin.parse_8bit();
                        if (tag == 'R') {
                            stack_trace->push_back_ptr(hin.get_ref_object(hin.parse_32bit()), false);
                            continue;
                        } else if (tag != 'M') {
                            throw io_exception(string(
                                        "fail to parse field 'stackTrace', expecting 'M' but actually: ")
                                    .append(1, tag));
                        }
                        string* st_element = new string();
                        String* element = new String(st_element, true, hin.read_type());
                        stack_trace->push_back_ptr(element, true);
                        hin.add_ref(element);

                        string declaringClass;
                        string fileName;
                        int    lineNumber = -1;
                        string methodName;
                        while (hin.peek() != 'z') {
                            string st_key;
                            hin.read_utf8_string(&st_key);
                            if (st_key == "declaringClass") {
                                hin.read_chunked_utf8_string(&declaringClass);
                            } else if (st_key == "fileName") {
                                hin.read_chunked_utf8_string(&fileName);
                            } else if (st_key == "lineNumber") {
                                lineNumber = hin.read_int32();
                            } else if (st_key == "methodName") {
                                hin.read_chunked_utf8_string(&methodName);
                            } else {
                                pair<Object*, bool> ret = hin.read_object();
                                if (ret.second) {
                                    delete ret.first; // skip other fields
                                }
                            }
                        }
                        hin.seek(1); // skip 'z' for "StackTraceElement" end

                        st_element->append(declaringClass).append(1, '.').append(methodName);
                        if (lineNumber == -2) {
                            st_element->append("(Native Method)");
                        } else if (fileName.empty()) {
                            st_element->append("(Unknown Source)");
                        } else {
                            st_element->append(1, '(').append(fileName);
                            if (lineNumber >= 0) {
                                st_element->append(1, ':').append(int32_to_string(lineNumber));
                            }
                            st_element->append(1, ')');
                        }
                    }
                    hin.seek(1); // skip 'z' for "[StackTraceElement" end
                } else if (tag != 'N') {
                    throw io_exception(string(
                                "fail to parse field 'stackTrace', encounter value tag: ").append(1, tag));
                }
            } else {
                // for other unknown fields
                pair<Object*, bool> ret = hin.read_object();
                ex->put(new String(key), ret.first, true, ret.second);
            }

        } else {
            throw io_exception(
                    "fail to parse field of class '" + type +
                    "', expecting key tag 'S' but actually met: " + (char) tag);
        }
    }

    hin.seek(1); // skip 'z' for end
    safeguard.release();
    return ex;
}

/* ==================================================================
 *  init
 * ================================================================ */
static struct hessian2_extension_initializer {
    hessian2_extension_initializer() {
        serializer_registry_hessian2.resize(300);
        serializer_registry_hessian2[NullObject::TYPE_ID] = &null_serialize_hessian2;
        serializer_registry_hessian2[Boolean::TYPE_ID] = &boolean_serialize_hessian2;
        serializer_registry_hessian2[Integer::TYPE_ID] = &integer_serialize_hessian2;
        serializer_registry_hessian2[Long::TYPE_ID] = &long_serialize_hessian2;
        serializer_registry_hessian2[Double::TYPE_ID] = &double_serialize_hessian2;
        serializer_registry_hessian2[Date::TYPE_ID] = &date_serialize_hessian2;
        serializer_registry_hessian2[String::TYPE_ID] = &string_serialize_hessian2;
        serializer_registry_hessian2[ByteArray::TYPE_ID] = &bytearray_serialize_hessian2;
        serializer_registry_hessian2[Reference::TYPE_ID] = &reference_serialize_hessian2;
        serializer_registry_hessian2[List::TYPE_ID] = &list_serialize_hessian2;
        serializer_registry_hessian2[Map::TYPE_ID] = &map_serialize_hessian2;
        serializer_registry_hessian2[Exception::TYPE_ID] = &exception_serialize_hessian2;
        hessian2_regist_deserializer(Object::EXT_MAP, "*Exception", &exception_deserialize);
        hessian2_regist_deserializer(Object::EXT_MAP, "*Error", &exception_deserialize);
    }
} hessian2_extension_init;

}
