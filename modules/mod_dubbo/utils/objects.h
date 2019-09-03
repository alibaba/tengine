#ifndef _HESSIAN_OBJECTS_H_
#define _HESSIAN_OBJECTS_H_

#include "exceptions.h"
#include <stdint.h>
#include <string>
#include <vector>
#include <map>

namespace hessian {

class List;
class Map;
class ObjectValue;

class Object {
    public:
        /**
         * Object type
         */
        typedef enum ObjectType {
            NULL_OBJECT = 0,                      // NULL
            BOOLEAN, INTEGER, LONG, DOUBLE, DATE, // basic type
            STRING, BYTE_ARRAY,                   // string byte
            WEAK_REF,                             // weak object

            //need ref on serializa
            LIST,                                 // list set
            MAP,                                  // map hashmap
            //extend type
            EXT_OBJECT = MAP + 1,                 // extend object (by serializa)
            EXT_LIST = 100,                       // extend object (by list)
            EXT_MAP = 200,                        // extend object (by map)
            EXCEPTION                             // exception
        } ObjectType;

        Object(const std::string& classname, uint32_t type_id)
            : _type_id(type_id), _classname(classname) {}

        virtual ~Object() {}

        /** object type **/
        uint32_t type_id() const { return _type_id; }

        /** object classname **/
        const std::string& classname() const { return _classname; }
        void set_classname(const std::string& classname) { _classname = classname; }

        /*
         * convert object to basic type (support weak convert, like long->int)
         * throw exception when failed
         */
        bool to_bool() const;
        int32_t to_int() const;
        int64_t to_long() const;
        double to_double() const;
        std::string to_string() const;
        List* to_list();
        Map* to_map();

        /** generate extend object type_id */
        static uint32_t generate_type_id(ObjectType ext_type);

    private:
        const uint32_t _type_id;

    protected:
        std::string _classname;

    private:
        Object(const Object& other);
        Object& operator=(const Object& other);
};

template <class T>
inline bool instance_of(const Object* obj) {
    return obj && obj->type_id() == T::TYPE_ID;
}

template <class T>
inline bool pointer_of(const Object* obj) {
    return !obj || obj->type_id() == T::TYPE_ID;
}

/**
 * null reference, equal in (Object*) NULL
 */
class NullObject : public Object {
    public:
        typedef void* data_type;
        static const uint32_t TYPE_ID = NULL_OBJECT;
        NullObject(const std::string& classname = "null") : Object(classname, TYPE_ID) {}

        bool is_null() const { return true; }
        data_type data() const { return NULL; }
};

/**
 * bool type, equal Java boolean/Boolean
 */
class Boolean : public Object {
    public:
        typedef bool data_type;
        static const uint32_t TYPE_ID = BOOLEAN;
        static const std::string DEFAULT_CLASSNAME;

        Boolean(data_type value, const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _value(value) {}

        bool to_bool() const { return _value; }
        data_type data() const { return _value; }
    protected:
        data_type _value;
};

/**
 * int32_t, equal Java byte/int/Integer/short/Short
 */
class Integer : public Object {
    public:
        typedef int32_t data_type;
        static const uint32_t TYPE_ID = INTEGER;
        static const std::string DEFAULT_CLASSNAME;

        Integer(data_type value, const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _value(value) {}

        int32_t to_int() const { return _value; }
        data_type data() const { return _value; }
    protected:
        data_type _value;
};

/**
 * int64_t, equal Java long/Long
 */
class Long : public Object {
    public:
        typedef int64_t data_type;
        static const uint32_t TYPE_ID = LONG;
        static const std::string DEFAULT_CLASSNAME;

        Long(data_type value, const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _value(value) {}

        int64_t to_long() const { return _value; }
        data_type data() const { return _value; }
    protected:
        data_type _value;
};

/**
 * double, equal Java double/Double/float/Float
 */
class Double : public Object {
    public:
        typedef double data_type;
        static const uint32_t TYPE_ID = DOUBLE;
        static const std::string DEFAULT_CLASSNAME;

        Double(data_type value, const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _value(value) {}

        double to_double() const { return _value; }
        data_type data() const { return _value; }
    protected:
        data_type _value;
};

/**
 * date type, equal Java java.util.Date
 * since UTC 1970.1.1
 */
class Date : public Object {
    public:
        typedef int64_t data_type;
        static const uint32_t TYPE_ID = DATE;
        static const std::string DEFAULT_CLASSNAME;

        Date(data_type value, const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _value(value) {}

        int64_t to_udc_date() const { return _value; }
        data_type data() const { return _value; }
    protected:
        data_type _value;
};

/**
 * string type, equal Java char/String/char[]/Character
 */
class String : public Object {
    public:
        typedef std::string data_type;
        static const uint32_t TYPE_ID = STRING;
        static const std::string DEFAULT_CLASSNAME;

        String(const char* utf_8_c_str, uint32_t size,
                const std::string& classname = DEFAULT_CLASSNAME);

        String(const char* utf_8_c_str,
                const std::string& classname = DEFAULT_CLASSNAME);

        String(const std::string& utf_8_str,
                const std::string& classname = DEFAULT_CLASSNAME);

        String(const std::string* utf_8_str_ptr,
                const std::string& classname = DEFAULT_CLASSNAME);

        String(std::string* utf_8_str_ptr, bool chain_delete = false,
                const std::string& classname = DEFAULT_CLASSNAME);

        virtual ~String();

        uint32_t size() const { return _str->size(); }

        std::string to_string() const { return *_str; };
        const data_type& data() const { return *_str; }

        /*
         * return real string point, and detach auto recycle
         * invoker need delete it
         * return NULL when real string no need auto recycle
         */
        std::string* detach();
    protected:
        std::string* _str;
    private:
        bool _chain_delete;
};

/**
 * byte type, equal Java byte[]/Byte/"[B"
 */
class ByteArray : public Object {
    public:
        typedef std::string data_type;
        static const uint32_t TYPE_ID = BYTE_ARRAY;
        static const std::string DEFAULT_CLASSNAME;

        ByteArray(const char* bytes, uint32_t size,
                const std::string& classname = DEFAULT_CLASSNAME);

        ByteArray(const char* bytes,
                const std::string& classname = DEFAULT_CLASSNAME);

        ByteArray(const std::string& byte_str,
                const std::string& classname = DEFAULT_CLASSNAME);

        ByteArray(const std::string* byte_str_ptr,
                const std::string& classname = DEFAULT_CLASSNAME);

        ByteArray(std::string* byte_str_ptr, bool chain_delete = false,
                const std::string& classname = DEFAULT_CLASSNAME);

        virtual ~ByteArray();

        uint32_t size() const { return _str->size(); }

        std::string to_string() const { return *_str; }
        const data_type& data() const { return *_str; }

        /*
         * return real string point, and detach auto recycle
         * invoker need delete it
         * return NULL when real string no need auto recycle
         */
        std::string* detach();
    protected:
        std::string* _str;
    private:
        bool _chain_delete;
};

/*
 * ref type
 */
class Reference : public Object {
    public:
        typedef Object* data_type;
        static const uint32_t TYPE_ID = WEAK_REF;

        Reference(data_type value)
            : Object(value->classname(), TYPE_ID), _value(value), _chain_delete(false) {}
        Reference(data_type value, const std::string& classname, bool chain_delete = false)
            : Object(classname, TYPE_ID), _value(value), _chain_delete(chain_delete) {}

        ~Reference() { if (_chain_delete) delete _value; }

        data_type data() const { return _value; }
        data_type detach() { _chain_delete = false; return _value; }
    protected:
        data_type _value;
        bool      _chain_delete;
};

/**
 * list type, equal Java except char[] and byte[] array
 * and Collection/List/Set/Iterator/Enumeration¡£
 * object like "[Ljava.lang.Class;", "[Ljava.lang.Object;", "[Ljava.lang.String;"
 * maybe like "[java.lang.Class", "[object", "[string",
 * maybe need use Reference replace class name
 * for multidimensional array need multi "[". like "[[int", ¿¿"int[][]"
 */
class List : public Object {
    public:
        typedef std::vector<Object*> data_type;
        static const uint32_t TYPE_ID = LIST;
        static const std::string DEFAULT_CLASSNAME;

        List(const std::string& classname = DEFAULT_CLASSNAME, uint32_t type_id = TYPE_ID)
            : Object(classname, type_id) {}
        virtual ~List();

        void push_back_ptr(Object* element, bool chain_delete = false);
        void push_back(const ObjectValue& element, bool chain_delete = false);
        void add(const ObjectValue& element, bool chain_delete = false);
        void set(uint32_t pos, const ObjectValue& value, bool chain_delete = false);
        Object* get(uint32_t pos) const;

        const data_type& data() const { return _list; }

        uint32_t size() const { return _list.size(); }
        void reserve(uint32_t n) { _list.reserve(n); }

        // use operator[] for query purpose only
        Object* operator[] (uint32_t pos) const;

        /**
         * delete detachment from List's chain_delete, make it not auto recycle
         * invoker make sure recycle memory, if detachment is not auto recycle return null
         */
        bool detach(Object* detachment);
    protected:
        data_type _list;
        std::vector<Object*> _delete_chain;
};

template <>
inline bool instance_of<List>(const Object* obj) {
    return obj && (obj->type_id() == List::TYPE_ID ||
            (obj->type_id() >= Object::EXT_LIST && obj->type_id() < Object::EXT_MAP));
}

template <>
inline bool pointer_of<List>(const Object* obj) {
    return !obj || (obj->type_id() == List::TYPE_ID ||
            (obj->type_id() >= Object::EXT_LIST && obj->type_id() < Object::EXT_MAP));
}

/**
 * Object* comparer on Map 
 */
class object_ptr_less_comparator {
    public:
        bool operator() (const Object* const &left, const Object* const &right) const;
};

/**
 * map type, equal Java Map type
 */
class Map : public Object {
    public:
        typedef std::map<Object*, Object*, object_ptr_less_comparator> data_type;
        static const uint32_t TYPE_ID = MAP;
        static const std::string DEFAULT_CLASSNAME;

        Map(const std::string& classname = DEFAULT_CLASSNAME, uint32_t type_id = TYPE_ID)
            : Object(classname, type_id) {}
        virtual ~Map();

        void put(Object* key, Object* value,
                bool chain_delete_key = false, bool chain_delete_value = false);
        void put(const ObjectValue& key, const ObjectValue& value,
                bool chain_delete_key = false, bool chain_delete_value = false);
        Object* get(const ObjectValue& key) const;
        Object* get(const char* c_str_key) const;
        Object* get_ptr(Object* const key) const;

        const data_type& data() const { return _map; }

        uint32_t size() const { return _map.size(); }

        // use operator[] for query purpose only
        Object* operator[](const ObjectValue& key) const;

        /**
         * remote detachment from Map chain_delete, make it not auto recycle
         * invoker make sure delete detachment
         * if detachment is not auto recycle, may return false
         */
        bool detach(Object* detachment);
    protected:
        data_type _map;
        std::vector<Object*> _delete_chain;
};

template <>
inline bool instance_of<Map>(const Object* obj) {
    return obj && (obj->type_id() == Map::TYPE_ID || obj->type_id() >= Object::EXT_MAP);
}

template <>
inline bool pointer_of<Map>(const Object* obj) {
    return !obj || (obj->type_id() == Map::TYPE_ID || obj->type_id() >= Object::EXT_MAP);
}

/**
 * convert basic type to Object*
 */
class ObjectValue {
    public:
        ObjectValue(bool    bval) : _type(BVAL) { _value.bval = bval; }
        ObjectValue(int8_t  cval) : _type(CVAL) { _value.cval = cval; }
        ObjectValue(int16_t sval) : _type(SVAL) { _value.sval = sval; }
        ObjectValue(int32_t ival) : _type(IVAL) { _value.ival = ival; }
        ObjectValue(int64_t lval) : _type(LVAL) { _value.lval = lval; }
        ObjectValue(double  dval) : _type(DVAL) { _value.dval = dval; }

        ObjectValue(const char* c_char_ptr) : _type(C_CHAR_PTR) { _value.c_char_ptr = c_char_ptr; }
        ObjectValue(const std::string& str) : _type(C_STR_REF) { _value.c_str_ptr = &str; }
        ObjectValue(const std::string* c_str_ptr) : _type(C_STR_PTR) { _value.c_str_ptr = c_str_ptr; }
        ObjectValue(std::string* str_ptr) : _type(STR_PTR) { _value.str_ptr = str_ptr; }

        ObjectValue(Object* obj) : _type(OBJ) { _value.obj = obj; }
        ObjectValue(const Object* c_obj) : _type(C_OBJ) { _value.c_obj = c_obj; }

        /**
         * return ObjectValue for Object
         * pair.second mark Object need auto recycle
         */
        std::pair<Object*, bool> get_object() const;

    private:
        union {
            bool    bval;
            int8_t  cval;
            int16_t sval;
            int32_t ival;
            int64_t lval;
            double  dval;

            const char*   c_char_ptr;
            const std::string* c_str_ptr;
            std::string*       str_ptr;
            Object*       obj;
            const Object* c_obj;
        } _value;

        enum object_data_type {
            BVAL, CVAL, SVAL, IVAL, LVAL, DVAL,
            C_CHAR_PTR, C_STR_REF, C_STR_PTR, STR_PTR,
            OBJ, C_OBJ
        } _type;
};

/* ============================================================================
 * extend Java Object
 * ========================================================================= */
/**
 * exception object
 */
class Exception : public Map {
    public:
        static const std::string DEFAULT_CLASSNAME;
        static const uint32_t TYPE_ID = EXCEPTION;

        Exception(const std::string& detail_message = "", const std::string& classname = DEFAULT_CLASSNAME)
            : Map(classname, TYPE_ID), _detail_message(detail_message),
            _stack_trace(NULL), _cause(NULL) {}
        virtual ~Exception() {}

        const char* what() const { return _detail_message.c_str(); }

        void set_cause(Exception* cause, bool chain_delete = false) {
            _cause = cause; if (cause && chain_delete) _delete_chain.push_back(cause); }
        const Exception* cause() const { return _cause; }

        void set_detail_message(const std::string& message) { _detail_message = message; }
        std::string* mutable_detail_message() { return &_detail_message; }
        const std::string& detail_message() const { return _detail_message; }

        void set_stack_trace(List* stack_trace, bool chain_delete = false) {
            _stack_trace = stack_trace; if (stack_trace && chain_delete) _delete_chain.push_back(stack_trace); }
        const List* stack_trace() const { return _stack_trace; }

    protected:
        std::string _detail_message;
        List*       _stack_trace; // List<String*>*
        Exception*  _cause;
};

/**
 * warp C/C++ type to Object
 */
template <class T>
class ExtObject : public Object {
    public:
        typedef T data_type;
        static const uint32_t TYPE_ID;
        static const std::string DEFAULT_CLASSNAME;

        ExtObject(T* ptr,
                bool chain_delete = false,
                const std::string& classname = DEFAULT_CLASSNAME)
            : Object(classname, TYPE_ID), _ptr(ptr), _chain_delete(chain_delete) {}

        ~ExtObject() { if (_chain_delete) delete _ptr; }

        T* data() const { return _ptr; }
        void set_data(T* ptr) { if (_chain_delete) { delete _ptr; } _ptr = ptr; }
    protected:
        T*   _ptr;
        bool _chain_delete;
};

}
#endif
