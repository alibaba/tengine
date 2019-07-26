#include "json_text.h"
#include "utils.h"
#include <cstdio>
#include <sstream>
#include <ostream>

/*
 * Object Json output handle
 * @author jifeng
 */
namespace hessian {

using namespace std;

/* ==================================================================
 * handle regist
 * ================================================================ */
static vector<json_text_handler_pt> handlers;

void json_text_regist_handler(uint32_t type_id, json_text_handler_pt handler) {
    if (type_id >= handlers.size()) {
        handlers.resize(type_id + 1);
    }
    handlers[type_id] = handler;
}

/* ==================================================================
 * common handle
 * ================================================================ */
void json_text_handle_object(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    if (obj) {
        json_text_handler_pt handle = handlers[obj->type_id()];
        if (handle) {
            handle(obj, os, indent, dejaVu);
        } else {
            os << "{\"$class\":\"" << obj->classname() << "\"}";
        }
    } else {
        os << "null";
    }
}

int json_text_handle_dejaVu(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    pair<map<const Object*, int>::iterator, bool> ret = dejaVu->insert(
            pair<const Object*, int>(obj, dejaVu->size() + 1));
    if (!ret.second) {
        os << "\"$idref\":" << ret.first->second;
        return 0;
    }
    return ret.first->second;
}

void json_text_handle_list_element(const List* list, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    const List::data_type& data = list->data();
    os << '[';
    List::data_type::const_iterator it = data.begin();
    if (it != data.end()) {
        json_text_handle_object(*it, os, indent, dejaVu);
        while (++it != data.end()) {
            os << ',';
            json_text_handle_object(*it, os, indent, dejaVu);
        }
    }
    os << ']';
}

void json_text_handle_map_element(const Map* amap, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    const Map::data_type& data = amap->data();
    if (!data.empty()) {
        for (Map::data_type::const_iterator it = data.begin(); it != data.end(); ++it) {
            // only support key is string
            if (instance_of<String>((*it).first)) {
                os << ',';
                json_text_handle_object((*it).first, os, indent, dejaVu);
                os << ':';
                json_text_handle_object((*it).second, os, indent, dejaVu);
            }
        }
    }
}

static void write_unicode(ostream& os, int32_t code) {
    char buf[8];
    snprintf(buf, 8, "\\u%04x", (code & 0xffff));
    os.write(buf, 6);
}

void json_text_string_escape(const void* ptr, unsigned int len, ostream& os) {
    os << '"';
    const char* p = static_cast<const char*>(ptr);
    const char* e = p + len;
    while (p < e) {
        char ch = *p++;
        if ((ch & 0xe0) == 0) {
            switch (ch) {
                case '\b': os << '\\' << 'b'; break;
                case '\n': os << '\\' << 'n'; break;
                case '\t': os << '\\' << 't'; break;
                case '\f': os << '\\' << 'f'; break;
                case '\r': os << '\\' << 'r'; break;
                default: write_unicode(os, ch);
            }
        } else if ((ch & 0x80) == 0) {
            switch (ch) {
                case '\'': os << '\\' << '\''; break;
                case '"': os << '\\' << '"'; break;
                case '\\': os << '\\' << '\\'; break;
                default : os << ch;
            }
        } else {
            // more than one char
            int32_t code = 0;
            char ch2 = *p++;
            if ((ch & 0xe0) == 0xc0) { // 110xxxxx 10xxxxxx
                code = ((int32_t)(ch & 0x1f) << 6)
                    | (ch2 & 0x3f);
            } else if ((ch & 0xf0) == 0xe0) { // 1110xxxx 10xxxxxx 10xxxxxx
                char ch3 = *p++;
                code = ((int32_t)(ch & 0x0f) << 12)
                    | ((int32_t)(ch2 & 0x3f) << 6)
                    | (ch3 & 0x3f);
            } else { // 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
                char ch3 = *p++;
                char ch4 = *p++;
                code = ((int32_t)(ch & 0x07) << 18)
                    | ((int32_t)(ch2 & 0x3f) << 12)
                    | ((int32_t)(ch3 & 0x3f) << 6)
                    | (ch4 & 0x3f);
            }
            write_unicode(os, code);
        }
    }
    os << '"';
}

/* ==================================================================
 * handlers
 * ================================================================ */
static void null_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << "null";
}

static void boolean_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << (static_cast<const Boolean*>(obj)->data() ? "true" : "false");
}

static void integer_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << static_cast<const Integer*>(obj)->data();
}

static void long_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << static_cast<const Long*>(obj)->data();
}

static void double_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << static_cast<const Double*>(obj)->data();
}

static void date_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << "{\"$class\":\"" << obj->classname() << "\",\"$\":" << static_cast<const Date*>(obj)->data() << '}';
}

static void string_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    json_text_string_escape(static_cast<const String*>(obj)->data(), os);
}

static void bytearray_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << "{\"$class\":\"" << obj->classname() << "\",\"$\":\"";
    const char* p = static_cast<const ByteArray*>(obj)->data().data();
    const char* e = p + static_cast<const ByteArray*>(obj)->data().size();
    while (p < e) {
        char ch = *p++;
        if ((ch & 0xe0) == 0) {
            switch (ch) {
                case '\b': os << '\\' << 'b'; break;
                case '\n': os << '\\' << 'n'; break;
                case '\t': os << '\\' << 't'; break;
                case '\f': os << '\\' << 'f'; break;
                case '\r': os << '\\' << 'r'; break;
                default: write_unicode(os, ch);
            }
        } else if ((ch & 0x80) == 0) {
            switch (ch) {
                case '\'': os << '\\' << '\''; break;
                case '"': os << '\\' << '"'; break;
                case '\\': os << '\\' << '\\'; break;
                default : os << ch;
            }
        } else {
            write_unicode(os, ch);
        }
    }
    os << '"' << '}';
}

static void reference_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    json_text_handle_object(static_cast<const Reference*>(obj)->data(), os, indent, dejaVu);
}

static void list_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << "{\"$class\":\"" << obj->classname() << "\",";
    int id;
    if ((id = json_text_handle_dejaVu(obj, os, ++indent, dejaVu)) != 0) {
        os << "\"$id\":" << id
            << ",\"$\":";
        json_text_handle_list_element(static_cast<const List*>(obj), os, indent, dejaVu);
    }
    os << '}';
}

static void map_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    os << "{\"$class\":\"" << obj->classname() << "\",";
    int id;
    if ((id = json_text_handle_dejaVu(obj, os, ++indent, dejaVu)) != 0) {
        os << "\"$id\":" << id;
        json_text_handle_map_element(static_cast<const Map*>(obj), os, indent, dejaVu);
    }
    os << '}';
}

static void exception_json_text(const Object* obj, ostream& os, int indent, map<const Object*, int>* dejaVu) {
    const Exception* ex = static_cast<const Exception*>(obj);
    os << "{\"$class\":\"" << ex->classname() << "\",";
    int id;
    if ((id = json_text_handle_dejaVu(obj, os, ++indent, dejaVu)) != 0) {
        os << "\"$id\":" << id
            << ",\"detailMessage\":";
        json_text_string_escape(ex->detail_message(), os);
        if (ex->stack_trace()) {
            os << ",\"stackTrace\":[";
            vector<Object*>::const_iterator it = ex->stack_trace()->data().begin();
            if (it != ex->stack_trace()->data().end()) {
                json_text_string_escape((*it)->to_string(), os);
                while (++it != ex->stack_trace()->data().end()) {
                    os << ',';
                    json_text_string_escape((*it)->to_string(), os);
                }
            }
        }
        if (ex->cause() && ex->cause() != ex) {
            os << ",\"cause\":";
            json_text_handle_object(ex->cause(), os, indent, dejaVu);
        }
        json_text_handle_map_element(static_cast<const Map*>(obj), os, indent, dejaVu);
    }
    os << '}';
}

/* ==================================================================
 * init
 * ================================================================ */
static struct json_text_handler_initializer {
    json_text_handler_initializer() {
        handlers.resize(300);
        handlers[NullObject::TYPE_ID] = &null_json_text;
        handlers[Boolean::TYPE_ID] = &boolean_json_text;
        handlers[Integer::TYPE_ID] = &integer_json_text;
        handlers[Long::TYPE_ID] = &long_json_text;
        handlers[Double::TYPE_ID] = &double_json_text;
        handlers[Date::TYPE_ID] = &date_json_text;
        handlers[String::TYPE_ID] = &string_json_text;
        handlers[ByteArray::TYPE_ID] = &bytearray_json_text;
        handlers[Reference::TYPE_ID] = &reference_json_text;
        handlers[List::TYPE_ID] = &list_json_text;
        handlers[Map::TYPE_ID] = &map_json_text;
        handlers[Exception::TYPE_ID] = &exception_json_text;
    }
} json_text_handler_init;

}
