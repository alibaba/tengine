#ifndef _HESSIAN_EXCEPTIONS_H_
#define _HESSIAN_EXCEPTIONS_H_

#include <string>

namespace hessian {

class Object;

class io_exception : public std::exception {
    public:
        explicit io_exception(const std::string& what): _message(what) {}
        virtual ~io_exception() throw() {}
        const char* what() const throw() { return _message.c_str(); }
        virtual void raise() const { throw *this; }
    protected:
        std::string _message;
};

class class_cast_exception : public std::exception {
    public:
        explicit class_cast_exception(const std::string& what): _message(what) {}
        virtual ~class_cast_exception() throw() {}
        const char* what() const throw() { return _message.c_str(); }
        virtual void raise() const { throw *this; }
    protected:
        std::string _message;
};

}

#endif
