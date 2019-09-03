#include "objects.h"
#include "utils.h"
#include "hessian2_output.h"
#include <sstream>

/*
 * Object implementation
 * @author jifeng
 */
namespace hessian {

using namespace std;

/*
 * maybe not init, cannot use on init
 */
const string Boolean::DEFAULT_CLASSNAME("boolean");
const string Integer::DEFAULT_CLASSNAME("int");
const string Long::DEFAULT_CLASSNAME("long");
const string Double::DEFAULT_CLASSNAME("double");
const string Date::DEFAULT_CLASSNAME("java.util.Date");
const string String::DEFAULT_CLASSNAME("java.lang.String");
const string ByteArray::DEFAULT_CLASSNAME("[B"); // byte[]
const string List::DEFAULT_CLASSNAME("java.util.ArrayList");
const string Map::DEFAULT_CLASSNAME("java.util.HashMap");
const string Exception::DEFAULT_CLASSNAME("java.lang.RuntimeException");

/**
 * ObjectValue implementations
 */
pair<Object*, bool> ObjectValue::get_object() const {
    /*
     * use get_object() convert value to Object
     * maybe need delete, need check pair.second
     */
    switch (_type) {
        case OBJ:        return pair<Object*, bool>(_value.obj, false);
        case C_OBJ:      return pair<Object*, bool>(_value.obj, false);
        case IVAL:       return pair<Object*, bool>(new Integer(_value.ival), true);
        case LVAL:       return pair<Object*, bool>(new Long(_value.lval), true);
        case BVAL:       return pair<Object*, bool>(new Boolean(_value.bval), true);
        case C_CHAR_PTR: return pair<Object*, bool>(new String(_value.c_char_ptr), true);
        case C_STR_REF:  return pair<Object*, bool>(new String(_value.c_str_ptr->c_str(), _value.c_str_ptr->size()), true); // ¿½±´
        case C_STR_PTR:  return pair<Object*, bool>(new String(_value.c_str_ptr), true);
        case STR_PTR:    return pair<Object*, bool>(new String(_value.str_ptr, false), true);
        case CVAL:       return pair<Object*, bool>(new String(new string(1, _value.cval), true, "char"), true);
        case SVAL:       return pair<Object*, bool>(new Integer(_value.sval), true);
        case DVAL:       return pair<Object*, bool>(new Double(_value.dval), true);
        default:         return pair<Object*, bool>(NULL, false);
    }
}

/**
 * Compare Object* in Map
 * sort on type_id first, than use value
 * sort on ptr when not base type
 */
bool object_ptr_less_comparator::operator() (const Object* const &left, const Object* const &right) const {
    if (left == NULL) {
        return right == NULL ? false : true;
    }
    if (right == NULL) {
        return false;
    }

    uint32_t left_obj_t = left->type_id();
    uint32_t right_obj_t = right->type_id();
    if (left_obj_t != right_obj_t) {
        return left_obj_t < right_obj_t;
    }

    switch (left_obj_t) {
        case Object::STRING:
            return ((String*) left)->to_string() < ((String*) right)->to_string();

        case Object::INTEGER:
            return ((Integer*) left)->to_int() < ((Integer*) right)->to_int();

        case Object::LONG:
            return ((Long*) left)->to_long() < ((Long*) right)->to_long();

        case Object::NULL_OBJECT:
            return false;

        case Object::BOOLEAN:
            return ((Boolean*) left)->to_bool() < ((Boolean*) right)->to_bool();

        case Object::DOUBLE:
            return ((Double*) left)->to_double() < ((Double*) right)->to_double();

        case Object::DATE:
            return ((Date*) left)->to_udc_date() < ((Date*) right)->to_udc_date();

        case Object::BYTE_ARRAY:
            return ((ByteArray*) left)->to_string() < ((ByteArray*) right)->to_string();

        case Object::LIST:
        case Object::MAP:
        default: // require identical equality
            return ((uintptr_t) left) < ((uintptr_t) right);
    }
}

/*
 * extend object type_id
 */
static uint32_t last_ext_object_id = Object::EXT_OBJECT;
static uint32_t last_ext_list_id = Object::EXT_LIST;
static uint32_t last_ext_map_id = Object::EXT_MAP;

uint32_t Object::generate_type_id(ObjectType ext_type) {
    switch (ext_type) {
        case Object::EXT_MAP:
            return ++last_ext_map_id;
        case Object::EXT_LIST:
            return ++last_ext_list_id;
        case Object::EXT_OBJECT:
        default:
            return ++last_ext_object_id;
    }
}

/*
 * Object implementations
 */
bool Object::to_bool() const {
    switch (type_id()) {
        case BOOLEAN: return ((Boolean*) this)->to_bool();
        case INTEGER: return ((Integer*) this)->to_int() == 0;
        case LONG:    return ((Long*) this)->to_long() == 0L;
        case DOUBLE:  return ((Double*) this)->to_double() == 0.0;
        case STRING:  return ((String*) this)->to_string() == "true";
        default:
                      throw class_cast_exception("can not cast to bool from class: " + _classname);
    }
}

int32_t Object::to_int() const {
    switch (type_id()) {
        case INTEGER: return ((Integer*) this)->to_int();
        case LONG:    return (int32_t) ((Long*) this)->to_long();
        case BOOLEAN: return (int32_t) ((Boolean*) this)->to_bool();
        case DOUBLE:  return (int32_t) ((Double*) this)->to_double();
        case STRING:  return string_to_int32(((String*) this)->to_string());
        default:
                      throw class_cast_exception("can not cast to int from class: " + _classname);
    }
}

int64_t Object::to_long() const {
    switch (type_id()) {
        case LONG:    return ((Long*) this)->to_long();
        case INTEGER: return (int64_t) ((Integer*) this)->to_int();
        case DATE:    return ((Date*) this)->to_udc_date();
        case BOOLEAN: return (int64_t) ((Boolean*) this)->to_bool();
        case DOUBLE:  return (int64_t) ((Double*) this)->to_double();
        case STRING:  return string_to_int64(((String*) this)->to_string());
        default:
                      throw class_cast_exception("can not cast to long from class: " + _classname);
    }
}

double Object::to_double() const {
    switch (type_id()) {
        case DOUBLE:  return ((Double*) this)->to_double();
        case LONG:    return (double) ((Long*) this)->to_long();
        case INTEGER: return (double) ((Integer*) this)->to_int();
        case BOOLEAN: return (double) ((Boolean*) this)->to_bool();
        case STRING:  return string_to_double(((String*) this)->to_string());
        default:
                      throw class_cast_exception("can not cast to double from class: " + _classname);
    }
}

string Object::to_string() const {
    switch (type_id()) {
        case STRING:     return ((String*) this)->data();
        case LONG:       return int64_to_string(((Long*) this)->to_long());
        case INTEGER:    return int32_to_string(((Integer*) this)->to_int());
        case BOOLEAN:    return bool_to_string(((Boolean*) this)->to_bool());
        case DOUBLE:     return double_to_string(((Double*) this)->to_double());
        case DATE:       return int64_to_string(((Date*) this)->to_udc_date());
        case BYTE_ARRAY: return ((ByteArray*) this)->to_string();
        default:
                         throw class_cast_exception("can not cast to string from class: " + _classname);
    }
}

List* Object::to_list() {
    if (!instance_of<List>(this)) {
        throw class_cast_exception("can not cast to list from class: " + _classname);
    }
    return static_cast<List*>(this);
}

Map* Object::to_map() {
    if (!instance_of<Map>(this)) {
        throw class_cast_exception("can not cast to map from class: " + _classname);
    }
    return static_cast<Map*>(this);
}

/*
 * String implementations
 */
String::String(const char* utf_8_c_str, uint32_t size, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(utf_8_c_str, size)), _chain_delete(true) {
    }

String::String(const char* utf_8_c_str, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(utf_8_c_str)), _chain_delete(true) {
    }

String::String(const string& utf_8_str, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(utf_8_str)), _chain_delete(true) {
    }

String::String(const string* utf_8_str_ptr, const string& classname)
    : Object(classname, TYPE_ID),
    _str(const_cast<string*>(utf_8_str_ptr)), _chain_delete(false) {
    }

String::String(string* utf_8_str_ptr, bool chain_delete, const string& classname)
    : Object(classname, TYPE_ID),
    _str(utf_8_str_ptr), _chain_delete(chain_delete) {
    }

String::~String() {
    if (_chain_delete) {
        delete _str;
    };
}

string* String::detach() {
    if (_chain_delete) {
        _chain_delete = false;
        return _str;
    } else {
        return NULL;
    }
}

/*
 * ByteArray implementations
 */
ByteArray::ByteArray(const char* bytes, uint32_t size, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(bytes, size)), _chain_delete(true) {
    }

ByteArray::ByteArray(const char* bytes, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(bytes)), _chain_delete(true) {
    }

ByteArray::ByteArray(const string& byte_str, const string& classname)
    : Object(classname, TYPE_ID),
    _str(new string(byte_str)), _chain_delete(true) {
    }

ByteArray::ByteArray(const string* byte_str_ptr, const string& classname)
    : Object(classname, TYPE_ID),
    _str(const_cast<string*>(byte_str_ptr)), _chain_delete(false) {
    }

ByteArray::ByteArray(string* byte_str_ptr, bool chain_delete, const string& classname)
    : Object(classname, TYPE_ID),
    _str(byte_str_ptr), _chain_delete(chain_delete) {
    }

ByteArray::~ByteArray() {
    if (_chain_delete) {
        delete _str;
    };
}

string* ByteArray::detach() {
    if (_chain_delete) {
        _chain_delete = false;
        return _str;
    } else {
        return NULL;
    }
}

/*
 * List implementations
 */
List::~List() {
    for (data_type::iterator it = _delete_chain.begin() ; it != _delete_chain.end(); ++it) {
        delete (*it);
    }
}

void List::push_back_ptr(Object* element, bool chain_delete) {
    if (chain_delete) {
        _delete_chain.push_back(element);
    }
    _list.push_back(element);
}

void List::push_back(const ObjectValue& element, bool chain_delete) {
    pair<Object*, bool> ret = element.get_object();
    if (ret.second || chain_delete) {
        _delete_chain.push_back(ret.first);
    }
    _list.push_back(ret.first);
}

void List::add(const ObjectValue& element, bool chain_delete) {
    push_back(element, chain_delete);
}

void List::set(uint32_t pos, const ObjectValue& value, bool chain_delete) {
    pair<Object*, bool> ret = value.get_object();
    if (ret.second || chain_delete) {
        _delete_chain.push_back(ret.first);
    }
    _list.at(pos) = ret.first;
}

Object* List::get(uint32_t pos) const {
    return _list.at(pos);
}

Object* List::operator[] (uint32_t pos) const {
    return get(pos);
}

bool List::detach(Object* detachment) {
    for (vector<Object*>::iterator it = _delete_chain.begin(); it != _delete_chain.end(); ++it) {
        if ((*it) == detachment) {
            _delete_chain.erase(it);
            return true;
        }
    }
    return false;
}

/*
 * Map implementations
 */
Map::~Map() {
    for (vector<Object*>::iterator it = _delete_chain.begin(); it != _delete_chain.end(); ++it) {
        delete *it;
    }
}

void Map::put(Object* key, Object* value,
        bool chain_delete_key, bool chain_delete_value) {
    if (chain_delete_key) {
        _delete_chain.push_back(key);
    }
    if (chain_delete_value) {
        _delete_chain.push_back(value);
    }
    _map[key] = value;
}

void Map::put(const ObjectValue& key, const ObjectValue& value,
        bool chain_delete_key, bool chain_delete_value) {
    pair<Object*, bool> ret_key = key.get_object();
    pair<Object*, bool> ret_value = value.get_object();
    if (ret_key.second || chain_delete_key) {
        _delete_chain.push_back(ret_key.first);
    }
    if (ret_value.second || chain_delete_value) {
        _delete_chain.push_back(ret_value.first);
    }
    _map[ret_key.first] = ret_value.first;
}

Object* Map::get(const ObjectValue& key) const {
    pair<Object*, bool> ret_key = key.get_object();
    data_type::const_iterator it = _map.find(ret_key.first);
    if (ret_key.second) {
        delete ret_key.first;
    }
    if (it == _map.end()) {
        return NULL;
    } else {
        return (*it).second;
    }
}

Object* Map::get(const char* c_str_key) const {
    const string key_str(c_str_key);
    String key(const_cast<string*>(&key_str), false);
    data_type::const_iterator it = _map.find(&key);
    if (it == _map.end()) {
        return NULL;
    } else {
        return (*it).second;
    }
}

Object* Map::get_ptr(Object* const key) const {
    data_type::const_iterator it = _map.find(key);
    if (it == _map.end()) {
        return NULL;
    } else {
        return (*it).second;
    }
}

Object* Map::operator[](const ObjectValue& key) const {
    return get(key);
}

bool Map::detach(Object* detachment) {
    for (vector<Object*>::iterator it = _delete_chain.begin(); it != _delete_chain.end(); ++it) {
        if ((*it) == detachment) {
            _delete_chain.erase(it);
            return true;
        }
    }
    return false;
}

}
