#ifndef _HESSIAN_JSON_TEXT_H_
#define _HESSIAN_JSON_TEXT_H_

#include "objects.h"
#include <map>
#include <iosfwd>

namespace hessian {

/**
 * Json output object
 *
 * @param obj object
 * @param os dest stream
 * @param indent current indest number
 * @param dejaVu outputed object list
 */
typedef void (*json_text_handler_pt)(const Object* obj,
                                     std::ostream& os,
                                     int indent,
                                     std::map<const Object*, int>* dejaVu);

/**
 * Extend Debug Text output handler 
 *
 * @param type_id object type_id
 * @param handler object Json output handler
 */
void json_text_regist_handler(uint32_t type_id, json_text_handler_pt handler);

/**
 * Output obj to os
 * @param obj object
 * @param os dest stream
 * @param indent current indent number
 * @param dejaVu outputed object list
 */
void json_text_handle_object(const Object* obj,
                             std::ostream& os,
                             int indent,
                             std::map<const Object*, int>* dejaVu);

/**
 * Check object outputed help, return object $id,
 */
int json_text_handle_dejaVu(const Object* obj,
                            std::ostream& os,
                            int indent,
                            std::map<const Object*, int>* dejaVu);

/**
 * Output items in List help
 */
void json_text_handle_list_element(const List* list,
                                   std::ostream& os,
                                   int indent,
                                   std::map<const Object*, int>* dejaVu);

/**
 * Output key/value in map help
 */
void json_text_handle_map_element(const Map* amap,
                                  std::ostream& os,
                                  int indent,
                                  std::map<const Object*, int>* dejaVu);

/**
 * Handle string escape, ptr ponit to UTF-8 string chunk
 */
void json_text_string_escape(const void* ptr,
                             unsigned int len,
                             std::ostream& os);

inline void json_text_string_escape(const std::string& str, std::ostream& os) {
  json_text_string_escape(str.data(), str.size(), os);
}

}
#endif
