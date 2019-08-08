#ifndef _HESSIAN2_EXTENSION_H_
#define _HESSIAN2_EXTENSION_H_

#include "objects.h"
#include <string>

namespace hessian {

class hessian2_input;
class hessian2_output;

typedef void (*hessian2_serialize_pt)(const Object* obj, hessian2_output& hout);

typedef Object* (*hessian2_deserialize_pt)(const std::string& type, hessian2_input& hin);

void hessian2_regist_serializer(uint32_t type_id, hessian2_serialize_pt serializer);

void hessian2_regist_deserializer(Object::ObjectType ext_type, const std::string& type, hessian2_deserialize_pt deserializer);

hessian2_serialize_pt hessian2_get_serializer(const Object* obj);

hessian2_deserialize_pt hessian2_get_deserializer(Object::ObjectType ext_type, const std::string& type);

}
#endif
