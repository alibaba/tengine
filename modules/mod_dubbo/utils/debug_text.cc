#include "debug_text.h"
#include "utils.h"
#include <sstream>
#include <ostream>

/*
 * Object debug output implement
 * @author jifeng
 */
namespace hessian {

using namespace std;

/* ==================================================================
 *  handler regist
 * ================================================================ */
static vector<debug_text_handler_pt> handlers;

void debug_text_regist_handler(uint32_t type_id, debug_text_handler_pt handler) {
    if (type_id >= handlers.size()) {
        handlers.resize(type_id + 1);
    }
    handlers[type_id] = handler;
}

/* ==================================================================
 *  handler common
 * ================================================================ */
void debug_text_handle_object(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    if (obj) {
        debug_text_handler_pt handle = handlers[obj->type_id()];
        if (handle) {
            handle(obj, os, indent, dejaVu);
        } else {
            os << obj->classname()
                << " - Object, addr=" << (uintptr_t) obj
                << "\n";
        }
    } else {
        os << "null\n";
    }
}

bool debug_text_handle_dejaVu(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    pair<set<const Object*>::iterator, bool> ret = dejaVu->insert(obj);
    if (!ret.second) {
        os << string(indent << 1, ' ') << "[...]\n";
        return false;
    }
    return true;
}

void debug_text_handle_list_element(const List* list, ostream& os, int indent, set<const Object*>* dejaVu) {
    int i = 0;
    const List::data_type& data = list->data();
    for (List::data_type::const_iterator it = data.begin(); it != data.end(); ++it) {
        os << string(indent << 1, ' ') << "[" << i++ << "] ";
        debug_text_handle_object(*it, os, indent, dejaVu);
    }
}

void debug_text_handle_map_element(const Map* map, ostream& os, int indent, set<const Object*>* dejaVu) {
    const Map::data_type& data = map->data();
    if (!data.empty()) {
        int i = 0;
        for (Map::data_type::const_iterator it = data.begin(); it != data.end(); ++it) {
            const Object* key = (*it).first;
            const Object* val = (*it).second;
            ++i;

            if (instance_of<String>(key)) {
                os << string(indent << 1, ' ') << "[\"" << ((String*) key)->to_string() << "\"] ";
            } else {
                os << string(indent << 1, ' ') << "[key_" << i << "] ";
                debug_text_handle_object(key, os, indent, dejaVu);
                os << string(indent << 1, ' ') << "[val_" << i << "] ";
            }
            debug_text_handle_object(val, os, indent, dejaVu);
        }
    }
}

/* ==================================================================
 * handlers
 * ================================================================ */
static void null_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << "NullObject: null of class " << obj->classname() << "\n";
}

static void boolean_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << (static_cast<const Boolean*>(obj)->data() ? "true" : "false")
        << " - Boolean: " << obj->classname() << "\n";
}

static void integer_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << static_cast<const Integer*>(obj)->data() << " - Integer: " << obj->classname() << "\n";
}

static void long_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << static_cast<const Long*>(obj)->data() << "L - Long: " << obj->classname() << "\n";
}

static void double_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << static_cast<const Double*>(obj)->data() << " - Double: " << obj->classname() << "\n";
}

static void date_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << static_cast<const Date*>(obj)->data() << " - Date: " << obj->classname() << "\n";
}

static void string_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    // convert utf8 to native for debug
    os << "\"" << utf8_to_native(static_cast<const String*>(obj)->data()) << "\" - String: " << obj->classname()
        << ", size=" << static_cast<const String*>(obj)->size() << "\n";
}

static void bytearray_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << obj->classname()
        << " - ByteArray, size=" << static_cast<const ByteArray*>(obj)->size()
        << ", value=";
    write_hex_to_stream(os, static_cast<const ByteArray*>(obj)->data().data(),
            static_cast<const ByteArray*>(obj)->size());
    os << "\n";
}

static void reference_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << "Reference: " << obj->classname() << "\n"
        << string(++indent << 1, ' ');
    debug_text_handle_object(static_cast<const Reference*>(obj)->data(), os, indent, dejaVu);
}

static void list_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << obj->classname()
        << " - List, size=" << static_cast<const List*>(obj)->size()
        << ", addr=" << (uintptr_t) obj
        << "\n";

    if (debug_text_handle_dejaVu(obj, os, ++indent, dejaVu)) {
        debug_text_handle_list_element(static_cast<const List*>(obj), os, indent, dejaVu);
    }
}

static void map_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    os << obj->classname()
        << " - Map, size=" << static_cast<const Map*>(obj)->size()
        << ", addr=" << (uintptr_t) obj
        << "\n";

    if (debug_text_handle_dejaVu(obj, os, ++indent, dejaVu)) {
        debug_text_handle_map_element(static_cast<const Map*>(obj), os, indent, dejaVu);
    }
}

static void exception_debug_text(const Object* obj, ostream& os, int indent, set<const Object*>* dejaVu) {
    const Exception* ex = static_cast<const Exception*>(obj);
    os << ex->classname()
        << " - Exception, addr=" << (uintptr_t) ex
        << "\n";

    if (debug_text_handle_dejaVu(ex, os, ++indent, dejaVu)) {
        os << string(indent << 1, ' ') << "detail_message: " << utf8_to_native(ex->detail_message()) << "\n";

        if (ex->stack_trace()) {
            os << string(indent << 1, ' ') << "stack_trace: \n";
            ++indent;
            for (vector<Object*>::const_iterator it = ex->stack_trace()->data().begin();
                    it != ex->stack_trace()->data().end(); ++it) {
                os << string(indent << 1, ' ') << "  at " << (*it)->to_string() << '\n';
            }
            --indent;
        } else {
            os << string(indent << 1, ' ') << "stack_trace: null\n";
        }

        if (ex->cause() && ex->cause() != ex) {
            os << string(indent << 1, ' ') << "Cause by: ";
            if (ex->cause()) {
                debug_text_handle_object(ex->cause(), os, indent, dejaVu);
            } else {
                os << "null\n";
            }
        }

        debug_text_handle_map_element(ex, os, indent, dejaVu);
    }
}

/* ==================================================================
 * init
 * ================================================================ */
static struct debug_text_handler_initializer {
    debug_text_handler_initializer() {
        handlers.resize(300);
        handlers[NullObject::TYPE_ID] = &null_debug_text;
        handlers[Boolean::TYPE_ID] = &boolean_debug_text;
        handlers[Integer::TYPE_ID] = &integer_debug_text;
        handlers[Long::TYPE_ID] = &long_debug_text;
        handlers[Double::TYPE_ID] = &double_debug_text;
        handlers[Date::TYPE_ID] = &date_debug_text;
        handlers[String::TYPE_ID] = &string_debug_text;
        handlers[ByteArray::TYPE_ID] = &bytearray_debug_text;
        handlers[Reference::TYPE_ID] = &reference_debug_text;
        handlers[List::TYPE_ID] = &list_debug_text;
        handlers[Map::TYPE_ID] = &map_debug_text;
        handlers[Exception::TYPE_ID] = &exception_debug_text;
    }
} debug_text_handler_init;

}
